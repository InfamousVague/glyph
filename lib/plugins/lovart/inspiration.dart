/// Inspiration images: a moodboard of four made from a note, under its `## Inspiration` (Matt, 2026-10-26: "during
/// design meetings the Lovart.ai plugin can generate inspo images and such"). Pure: what is asked ([inspirationPrompt]),
/// where the pictures go ([inspirationInsert], [withInspiration]), and which meetings are design meetings
/// ([looksLikeDesignMeeting]).
library;

import '../../core/images.dart' show imageMarkdown;
import '../../core/note_text.dart' show noteTitle, withoutFrontMatter;
import '../../core/summary_text.dart' show summarySection;

/// The section's heading.
const String inspirationHeading = '## Inspiration';

/// How many images are asked for.
const int inspirationCount = 4;

/// How much of a note with no summary goes to Lovart.
const int inspirationChars = 1500;

/// What a note's inspiration is asked as: its title, then its summary where it has one, else its first
/// [inspirationChars] characters, and four images, one each, as Lovart takes counts only in words.
String inspirationPrompt(String body) {
  final title = noteTitle(body).trim();
  final summary = summarySection(body)?.text.replaceFirst(RegExp(r'^## Summary\s*'), '').trim();
  var about = summary != null && summary.isNotEmpty ? summary : withoutFrontMatter(body.split('\n')).join('\n').trim();
  // The pictures already there are not words to be inspired by.
  about = about.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (about.length > inspirationChars) about = '${about.substring(0, inspirationChars).trimRight()}…';
  return [
    'Make a moodboard of $inspirationCount inspiration images for the ideas in this note${title.isEmpty ? '' : ', “$title”'}.',
    'Make $inspirationCount separate images, one image each, each a different visual direction: style, colour palette, composition. No words or lettering in the images.',
    '',
    'The note:',
    about,
  ].join('\n');
}

/// Where the pictures [names] go in [body], as an edit of one line: after the last line of words under an
/// `## Inspiration` there already is, else after the note's last line of words, under a new heading. [line] is 1-based;
/// [add] is what goes after that line's text.
({int line, String add}) inspirationInsert(String body, List<String> names, {String caption = 'Inspiration'}) {
  final lines = body.split('\n');
  final pictures = [for (final name in names) imageMarkdown(name, caption)].join('\n');
  final heading = lines.indexWhere((l) => l.trim().toLowerCase() == inspirationHeading.toLowerCase());
  if (heading >= 0) {
    var end = heading;
    for (var i = heading + 1; i < lines.length; i += 1) {
      if (RegExp(r'^#{1,2}\s').hasMatch(lines[i])) break;
      if (lines[i].trim().isNotEmpty) end = i;
    }
    return (line: end + 1, add: '\n$pictures');
  }
  var last = lines.length - 1;
  while (last > 0 && lines[last].trim().isEmpty) {
    last -= 1;
  }
  final gap = lines[last].trim().isEmpty ? '' : '\n\n';
  return (line: last + 1, add: '$gap$inspirationHeading\n\n$pictures');
}

/// [body] with the pictures [names] under its `## Inspiration`.
String withInspiration(String body, List<String> names, {String caption = 'Inspiration'}) {
  final at = inspirationInsert(body, names, caption: caption);
  final lines = body.split('\n');
  lines[at.line - 1] = '${lines[at.line - 1]}${at.add}';
  return lines.join('\n');
}

/// The words that say a meeting is about design, each whole.
final List<RegExp> _designWords = [
  for (final word in const [
    r'design(?:s|ed|er|ers|ing)?',
    r'mock-?ups?',
    r'wireframes?',
    r'ui',
    r'ux',
    r'brand(?:s|ing)?',
    r'logos?',
    r'mood ?boards?',
    r'visuals?',
    r'palettes?',
    r'typography',
    r'typefaces?',
    r'layouts?',
    r'prototypes?',
    r'illustrations?',
    r'figma',
    r'style ?guides?',
    r'icons?',
    r'colou?r schemes?',
    r'look and feel',
  ])
    RegExp('(?<![\\p{L}\\p{N}])$word(?![\\p{L}\\p{N}])', caseSensitive: false, unicode: true),
];

int _hits(String text) => _designWords.where((w) => w.hasMatch(text)).length;

/// Whether a meeting is a design meeting, by its title and its summary: a design word in the title, or at least two
/// different ones in the summary, so a stand-up that mentions the UI once is not one.
bool looksLikeDesignMeeting(String title, String summary) => _hits(title) >= 1 || _hits(summary) >= 2;
